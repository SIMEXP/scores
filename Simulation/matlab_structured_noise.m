clear all; close all;
%% Set the settings
fig_path = '/home/surchs/Code/Projects/Scores/Simulation/figures/structured_mouse';
psom_mkdir(fig_path);

edge = 64;
n_edge = edge/4;
% Define the three networks
corner_net = 1;
border_net = 6;
ref_net1 = 2;
ref_net2 = 5;
networks = [1 2 5 6];
n_nets = length(networks);
net_names = {'corner', 'reference1', 'reference2', 'border'};
noise_levels = [0.1, 1, 5];
n_perm = 100;

opt_s.type = 'checkerboard';
opt_s.t = 100;
opt_s.n = edge*edge;
opt_s.nb_clusters = [4 16];
opt_s.variance = 0.05;
opt_s.fwhm = 4;

opt_scores.sampling.type = 'bootstrap';
opt_scores.sampling.opt = opt_s;

n_ref = 100;
ref_fpr = linspace(0,1,n_ref);
ref_thr = linspace(-1,1,n_ref);

%% Dry run to get the priors
[tseries,opt_mplm] = niak_simus_scenario(opt_s);
% Get the priors
prior_true_vec = opt_mplm.space.mpart{2};
prior_true = reshape(prior_true_vec, [edge, edge]);

corner_true_labels = prior_true==corner_net;
corner_true_labels = corner_true_labels(:);

border_true_labels = prior_true==border_net;
border_true_labels = border_true_labels(:);
target_prior = repmat(prior_true_vec, 1,2);

%% Generate the noise masks
% Generate a 3 wide mask for the structured noise
diag_mask = diag(ones(edge,1));
diag_mask = diag_mask + diag(ones(edge-1,1),1);
diag_mask = diag_mask + diag(ones(edge-1,1),-1);
% Generate the square matrix with structured noise
square_mask = zeros(edge, edge);
pos = zeros(4,2);
pos(1, 1) = 1;
pos(2:end, 1) = ((1:3)*edge/4)-1;
pos(:, 2) = (1:4)*edge/4;
pos_vec = pos(:);
square_mask(pos_vec, :) = 1;
square_mask(:, pos_vec) = 1;
% Mouse

[rr cc] = meshgrid(1:edge);
%C = sqrt((rr-16).^2+(cc-16).^2)<=10;
x = 16;
y = 16;
left_ear = sqrt((rr-n_edge).^2+(cc-n_edge).^2)<=n_edge;
right_ear = sqrt((rr-n_edge*3).^2+(cc-n_edge).^2)<=n_edge;
face = sqrt((rr-n_edge*2).^2+(cc-n_edge*2.5).^2)<=n_edge*1.4;
left_eye = sqrt((rr-n_edge*1.5).^2+(cc-n_edge*2).^2)<=n_edge/2.5;
right_eye = sqrt((rr-n_edge*2.5).^2+(cc-n_edge*2).^2)<=n_edge/2.5;
mouth = zeros(edge,edge);
mouth(n_edge*3:n_edge*3+n_edge/4,n_edge*1.5:n_edge*2.5) = 1;
mousy = logical(left_ear + right_ear + face) - left_eye - right_eye - mouth;
%C = logical(C);
mouse_mask = logical(mousy);

%% Storage
% We need to store everything for all 3 noise levels and for both the clean
% and the noise affected data
% This needs to be stored:
%   1. The stability map (edge*edge)
%   2. The TPR (THR interp) (THR)
%   3. The FPR (THR interp) (THR)
%   4. The AUC (1)
%   5. The TPR (FPR interp) (FPR)
% Everything times two because of the clean and non-clean stuff

% Maps:
% 1 (clean/noise)
% 2 (voxels)
% 3 (networks)
% 4 (noise levels)
% 5 (permutations)
scores_map = zeros(2, edge*edge, 16, 3, n_perm);
seed_map = zeros(2, edge*edge, 16, 3, n_perm);
dureg_map = zeros(2, edge*edge, 16, 3, n_perm);

% ROC
% 1 (clean/noise)
% 2 (FPR/THR values)
% 3 (networks of interest)
% 4 (TPR_F/TPR_T/FPR_T)
% 5 (noise levels)
% 6 (permutations)
scores_roc = zeros(2, n_ref, n_nets, 3, 3, n_perm);
seed_roc = zeros(2, n_ref, n_nets, 3, 3, n_perm);
dureg_roc = zeros(2, n_ref, n_nets, 3, 3, n_perm);

% AUC
% 1 (clean/noise)
% 2 (networks of interest)
% 3 (noise levels)
% 4 (permutations)
scores_auc = zeros(2, n_nets, 3, n_perm);
seed_auc = zeros(2, n_nets, 3, n_perm);
dureg_auc = zeros(2, n_nets, 3, n_perm);

opt_scores.flag_verbose = false;
%% Iterate over noise and permutations
for i_id = 1:n_perm
    fprintf('Running permutation %d\n', i_id);
    %% Generate the simulated signal
    % We will use the same base signal for all the noise levels. This means
    % that all noise levels can be compared to the same reference map.
    % This also means that there is only one map, for the first noise
    % level. The rest is zero.
    [tseries, opt_mplm] = niak_simus_scenario(opt_s);
    
    %% Run methods without structured noise
    %% Scores
    opt_scores.flag_target = false;
    res_scores = niak_stability_cores(tseries,prior_true_vec,opt_scores);
    % Do nothing here, just save the maps
    scores_map(1, :, :, 1, i_id) = res_scores.stab_maps;
    %% Seed
    opt_t.type_center = 'mean';
    opt_t.correction = 'mean_var';
    tseed = niak_build_tseries(tseries,prior_true_vec,opt_t);
    seed_tmp = niak_fisher(corr(tseries,tseed))';
    % Do nothing here, just save the maps
    seed_map(1, :, :, 1, i_id) = seed_tmp';
    %% Dual Regression
    opt_t.type_center = 'mean';
    opt_t.correction = 'mean_var';
    tseed = niak_build_tseries(tseries,prior_true_vec,opt_t);
    tseed = niak_normalize_tseries(tseed);
    tseries_dual = niak_normalize_tseries(tseries);
    beta = niak_lse(tseries_dual,tseed);
    % Do nothing here, just save the maps
    dureg_map(1, :, :, 1, i_id) = beta';
    
    for n_id = 1:3
        % Do the noise stuff
        noise = noise_levels(n_id);
        fprintf('    noise %.3f\n', noise);
        %% Generate the noise
        noise_tseries = normrnd(0, noise, [1, opt_s.t]);
        noise_vol = reshape(repmat(noise_tseries, edge*edge, 1),  edge, edge, opt_s.t);
        % Multiply the noise with the noise mask to get the desired shape
        s_noise_vol = repmat(square_mask, 1, 1, opt_s.t) .* noise_vol;
        d_noise_vol = repmat(diag_mask, 1, 1, opt_s.t) .* noise_vol;
        m_noise_vol = repmat(mouse_mask, 1, 1, opt_s.t) .* noise_vol;
        % Now turn these things back into vectors because that's how we represent
        % the time series
        s_noise_vec = reshape(s_noise_vol, [edge*edge, opt_s.t]);
        d_noise_vec = reshape(d_noise_vol, [edge*edge, opt_s.t]);
        m_noise_vec = reshape(m_noise_vol, [edge*edge, opt_s.t]);
        % And add the noise to the time series, but flip it because niak uses a
        % retarded notation
        %s_tseries = tseries + s_noise_vec';
        %d_tseries = tseries + d_noise_vec';
        d_tseries = tseries + m_noise_vec';
        
        %% Run the methods with structured noise
        %% Scores
        opt_scores.flag_target = false;
        res_scores_d = niak_stability_cores(d_tseries,prior_true_vec,opt_scores);
        % Do nothing here, just save the maps
        scores_map(2, :, :, n_id, i_id) = res_scores_d.stab_maps;
        
        %% Seed
        opt_t.type_center = 'mean';
        opt_t.correction = 'mean_var';
        tseed = niak_build_tseries(d_tseries,prior_true_vec,opt_t);
        seed_tmp = niak_fisher(corr(d_tseries,tseed))';
        % Do nothing here, just save the maps
        seed_map(2, :, :, n_id, i_id) = seed_tmp';
        
        %% Dual Regression
        opt_t.type_center = 'mean';
        opt_t.correction = 'mean_var';
        tseed = niak_build_tseries(d_tseries,prior_true_vec,opt_t);
        tseed = niak_normalize_tseries(tseed);
        tseries_dual = niak_normalize_tseries(d_tseries);
        beta = niak_lse(tseries_dual,tseed);
        % Do nothing here, just save the maps
        dureg_map(2, :, :, n_id, i_id) = beta';        
    end
end

%% Generate the ROC measurements
% Iterate over the networks
for net_id = 1:n_nets
    network = networks(net_id);
    fprintf('Running network %d now\n', network);
    % Get the maps back
    scores_net = squeeze(scores_map(:, :, network, :, :));
    seed_net = squeeze(seed_map(:, :, network, :, :));
    dureg_net = squeeze(dureg_map(:, :, network, :, :));
    % Generate a label mask
    label_mask = prior_true_vec == network;
    % Iterate over the permutations
    for i_id = 1:n_perm
        % Get the current permutation
        scores_net_perm = scores_net(:, :, :, i_id);
        seed_net_perm = seed_net(:, :, :, i_id);
        dureg_net_perm = dureg_net(:, :, :, i_id);
        % Iterate over the noise levels
        for n_id = 1:3
            % Get the current noise level
            scores_net_noise = scores_net_perm(2, :, n_id);
            seed_net_noise = seed_net_perm(2, :, n_id);
            dureg_net_noise = dureg_net_perm(2, :, n_id);
            % Scores
            [scores_fpr, scores_tpr, scores_thr, scores_auc_tmp] = perfcurve(label_mask, scores_net_noise, true);
            % Append -1 and 1 to the threshold and fix the fpr and tpr
            % values so the interpolation doesn't fuck it up
            scores_thr = [1; scores_thr; -1];
            scores_fpr = [0; scores_fpr; 1];
            scores_tpr = [0; scores_tpr; 1];
            % Interpolate thr
            [~, scores_tpr_t] = clean_dupl(scores_thr, scores_tpr);
            [scores_thr_t, scores_fpr_t] = clean_dupl(scores_thr, scores_fpr);
            scores_tpr_tint = interp1(scores_thr_t, scores_tpr_t, ref_thr, 'linear', 'extrap');
            scores_fpr_tint = interp1(scores_thr_t, scores_fpr_t, ref_thr, 'linear', 'extrap');
            % Clean up duplicates and interpolate fpr
            [scores_fpr, scores_tpr] = clean_dupl(scores_fpr, scores_tpr);
            scores_tpr_fint = interp1(scores_fpr, scores_tpr, ref_fpr);
            % Store the results
            scores_roc(2, :, net_id, 1, n_id, i_id) = scores_tpr_fint;
            scores_roc(2, :, net_id, 2, n_id, i_id) = scores_tpr_tint;
            scores_roc(2, :, net_id, 3, n_id, i_id) = scores_fpr_tint;
            % AUC
            scores_auc(2, net_id, n_id, i_id) = scores_auc_tmp;
            
            % Seed
            [seed_fpr, seed_tpr, seed_thr, seed_auc_tmp] = perfcurve(label_mask, seed_net_noise, true);
            % Append -1 and 1 to the threshold and fix the fpr and tpr
            % values so the interpolation doesn't fuck it up
            seed_thr = [1; seed_thr; -1];
            seed_fpr = [0; seed_fpr; 1];
            seed_tpr = [0; seed_tpr; 1];
            % Interpolate thr
            [~, seed_tpr_t] = clean_dupl(seed_thr, seed_tpr);
            [seed_thr_t, seed_fpr_t] = clean_dupl(seed_thr, seed_fpr);
            seed_tpr_tint = interp1(seed_thr_t, seed_tpr_t, ref_thr, 'linear', 'extrap');
            seed_fpr_tint = interp1(seed_thr_t, seed_fpr_t, ref_thr, 'linear', 'extrap');
            % Interpolate fpr
            [seed_fpr, seed_tpr] = clean_dupl(seed_fpr, seed_tpr);
            seed_tpr_fint = interp1(seed_fpr, seed_tpr, ref_fpr);
            % Store the results
            seed_roc(2, :, net_id, 1, n_id, i_id) = seed_tpr_fint;
            seed_roc(2, :, net_id, 2, n_id, i_id) = seed_tpr_tint;
            seed_roc(2, :, net_id, 3, n_id, i_id) = seed_fpr_tint;
            % AUC
            seed_auc(2, net_id, n_id, i_id) = seed_auc_tmp;

            % Dual Regression
            [dureg_fpr, dureg_tpr, dureg_thr, dureg_auc_tmp] = perfcurve(label_mask, dureg_net_noise, true);
            % Append -1 and 1 to the threshold and fix the fpr and tpr
            % values so the interpolation doesn't fuck it up
            dureg_thr = [1; dureg_thr; -1];
            dureg_fpr = [0; dureg_fpr; 1];
            dureg_tpr = [0; dureg_tpr; 1];
            % Interpolate thr
            [~, dureg_tpr_t] = clean_dupl(dureg_thr, dureg_tpr);
            [dureg_thr_t, dureg_fpr_t] = clean_dupl(dureg_thr, dureg_fpr);
            dureg_tpr_tint = interp1(dureg_thr_t, dureg_tpr_t, ref_thr, 'linear', 'extrap');
            dureg_fpr_tint = interp1(dureg_thr_t, dureg_fpr_t, ref_thr, 'linear', 'extrap');
            % Interpolate fpr
            [dureg_fpr, dureg_tpr] = clean_dupl(dureg_fpr, dureg_tpr);
            dureg_tpr_fint = interp1(dureg_fpr, dureg_tpr, ref_fpr);
            % Store the results
            dureg_roc(2, :, net_id, 1, n_id, i_id) = dureg_tpr_fint;
            dureg_roc(2, :, net_id, 2, n_id, i_id) = dureg_tpr_tint;
            dureg_roc(2, :, net_id, 3, n_id, i_id) = dureg_fpr_tint;
            % AUC
            dureg_auc(2, net_id, n_id, i_id) = dureg_auc_tmp;
            
        end
        % Now do the same thing, but for the clean data
        scores_net_clean = scores_net_perm(1, :, 1);
        seed_net_clean = seed_net_perm(1, :, 1);
        dureg_net_clean = dureg_net_perm(1, :, 1);
        % Scores
        [scores_fpr, scores_tpr, scores_thr, scores_auc_tmp] = perfcurve(label_mask, scores_net_clean, true);
        % Append -1 and 1 to the threshold and fix the fpr and tpr
        % values so the interpolation doesn't fuck it up
        scores_thr = [1; scores_thr; -1];
        scores_fpr = [0; scores_fpr; 1];
        scores_tpr = [0; scores_tpr; 1];
        % Interpolate thr
        [~, scores_tpr_t] = clean_dupl(scores_thr, scores_tpr);
        [scores_thr_t, scores_fpr_t] = clean_dupl(scores_thr, scores_fpr);
        scores_tpr_tint = interp1(scores_thr_t, scores_tpr_t, ref_thr, 'linear', 'extrap');
        scores_fpr_tint = interp1(scores_thr_t, scores_fpr_t, ref_thr, 'linear', 'extrap');
        % Clean up duplicates and interpolate fpr
        [scores_fpr, scores_tpr] = clean_dupl(scores_fpr, scores_tpr);
        scores_tpr_fint = interp1(scores_fpr, scores_tpr, ref_fpr);
        % Store the results
        scores_roc(1, :, net_id, 1, 1, i_id) = scores_tpr_fint;
        scores_roc(1, :, net_id, 2, 1, i_id) = scores_tpr_tint;
        scores_roc(1, :, net_id, 3, 1, i_id) = scores_fpr_tint;
        % AUC
        scores_auc(1, net_id, 1, i_id) = scores_auc_tmp;
        
        % Seed
        [seed_fpr, seed_tpr, seed_thr, seed_auc_tmp] = perfcurve(label_mask, seed_net_clean, true);
        % Append -1 and 1 to the threshold and fix the fpr and tpr
        % values so the interpolation doesn't fuck it up
        seed_thr = [1; seed_thr; -1];
        seed_fpr = [0; seed_fpr; 1];
        seed_tpr = [0; seed_tpr; 1];
        % Interpolate thr
        [~, seed_tpr_t] = clean_dupl(seed_thr, seed_tpr);
        [seed_thr_t, seed_fpr_t] = clean_dupl(seed_thr, seed_fpr);
        seed_tpr_tint = interp1(seed_thr_t, seed_tpr_t, ref_thr, 'linear', 'extrap');
        seed_fpr_tint = interp1(seed_thr_t, seed_fpr_t, ref_thr, 'linear', 'extrap');
        % Interpolate fpr
        [seed_fpr, seed_tpr] = clean_dupl(seed_fpr, seed_tpr);
        seed_tpr_fint = interp1(seed_fpr, seed_tpr, ref_fpr);
        % Store the results
        seed_roc(1, :, net_id, 1, 1, i_id) = seed_tpr_fint;
        seed_roc(1, :, net_id, 2, 1, i_id) = seed_tpr_tint;
        seed_roc(1, :, net_id, 3, 1, i_id) = seed_fpr_tint;
        % AUC
        seed_auc(1, net_id, 1, i_id) = seed_auc_tmp;
        
        % Dual Regression
        [dureg_fpr, dureg_tpr, dureg_thr, dureg_auc_tmp] = perfcurve(label_mask, dureg_net_clean, true);
        % Append -1 and 1 to the threshold and fix the fpr and tpr
        % values so the interpolation doesn't fuck it up
        dureg_thr = [1; dureg_thr; -1];
        dureg_fpr = [0; dureg_fpr; 1];
        dureg_tpr = [0; dureg_tpr; 1];
        % Interpolate thr
        [~, dureg_tpr_t] = clean_dupl(dureg_thr, dureg_tpr);
        [dureg_thr_t, dureg_fpr_t] = clean_dupl(dureg_thr, dureg_fpr);
        dureg_tpr_tint = interp1(dureg_thr_t, dureg_tpr_t, ref_thr, 'linear', 'extrap');
        dureg_fpr_tint = interp1(dureg_thr_t, dureg_fpr_t, ref_thr, 'linear', 'extrap');
        % Interpolate fpr
        [dureg_fpr, dureg_tpr] = clean_dupl(dureg_fpr, dureg_tpr);
        dureg_tpr_fint = interp1(dureg_fpr, dureg_tpr, ref_fpr);
        % Store the results
        dureg_roc(1, :, net_id, 1, 1, i_id) = dureg_tpr_fint;
        dureg_roc(1, :, net_id, 2, 1, i_id) = dureg_tpr_tint;
        dureg_roc(1, :, net_id, 3, 1, i_id) = dureg_fpr_tint;
        % AUC
        dureg_auc(1, net_id, 1, i_id) = dureg_auc_tmp;
    end
end

%% Plot the maps of networks of interest
% Plot them noise by method (separate figures for the networks)

pos_mat = reshape(1:12, [3 4])';
opt_v.limits = [-1 1];
opt_v.color_map = niak_hot_cold;
figs = cell(n_nets, 1);
% iterate across networks
for net_id = 1:n_nets
    network = networks(net_id);
    n_pos = net_id+1;
    figs{net_id} = figure('position',[0 0 1200 1200], 'visible','off');
    clf;
    % Generate the 2D label for an overlay
    label_mask = prior_true==network;
    [x, y] = find(label_mask);
    pos_vec = [min(y), min(x), n_edge, n_edge];
    % Iterate across noise levels, last one is clean
    for n_id  = 1:4
        noise_id = n_id - 1;
        if n_id == 1
            % Scores
            scores = reshape(mean(squeeze(scores_map(1, :, network, 1, :)),2), [edge edge]);
            % Seed
            seed = reshape(mean(squeeze(seed_map(1, :, network, 1, :)),2), [edge edge]);
            % Dureg
            dureg = reshape(mean(squeeze(dureg_map(1, :, network, 1, :)),2), [edge edge]);
        else
            % Scores
            scores = reshape(mean(squeeze(scores_map(2, :, network, noise_id, :)),2), [edge edge]);
            % Seed
            seed = reshape(mean(squeeze(seed_map(2, :, network, noise_id, :)),2), [edge edge]);
            % Dureg
            dureg = reshape(mean(squeeze(dureg_map(2, :, network, noise_id, :)),2), [edge edge]);
        end
        
        figure(figs{net_id});
        % Scores
        pos = pos_mat(n_id, 1);
        subplot(4,3,pos);
        niak_visu_matrix(scores, opt_v);
        rectangle('Position', pos_vec, 'EdgeColor','w','LineWidth',1);
        set(gca,'XTickLabel', [], 'YTickLabel', []);
        if n_id == 1
            title('Scores');
        end
        if n_id == 1
            ylabel('no structured noise');
        else
            ylabel(sprintf('noise %.3f', noise_levels(noise_id)));
        end
        % Seed
        pos = pos_mat(n_id, 2);
        subplot(4,3,pos);
        niak_visu_matrix(seed, opt_v);
        rectangle('Position', pos_vec, 'EdgeColor','w','LineWidth',1);
        set(gca,'XTickLabel', [], 'YTickLabel', []);
        if n_id == 1
            title('Seed');
        end
        % Dureg
        pos = pos_mat(n_id, 3);
        subplot(4,3,pos);
        niak_visu_matrix(dureg, opt_v);
        rectangle('Position', pos_vec, 'EdgeColor','w','LineWidth',1);
        set(gca,'XTickLabel', [], 'YTickLabel', []);
        if n_id == 1
            title('Dual Regression');
        end
    end
    figure(figs{net_id});
    suptitle(sprintf('%s network', net_names{net_id}));
    set(figs{net_id},'PaperPositionMode','auto');
    print(figs{net_id}, [fig_path filesep sprintf('map_overview_%s_network.png', net_names{net_id})], '-dpng');
end

%% Plot ROC curves for the different networks
% Plot all networks onto one plot of network by noise and all methods in
% one ROC
pos_mat = reshape(1:20, [4 5])';
opt_v.limits = [-1 1];
opt_v.color_map = niak_hot_cold;
fig = figure('position',[0 0 1200 1200], 'visible','off');
clf;
% iterate across networks
for net_id = 1:n_nets
    network = networks(net_id);
    % Plot the network as a reference
    pos = pos_mat(1, net_id);
    subplot(5,4,pos);
    
    imagesc(reshape(prior_true_vec == network, [edge edge]));
    colormap(cool);
    set(gca, 'XTick', linspace(16,edge,4), 'YTick', linspace(16,edge,4));
    grid on;
    title(sprintf('%s network', net_names{net_id}));
    
    % Iterate across noise levels, first one is clean
    for n_id  = 1:4
        noise_id = n_id - 1;
        if n_id == 1
            % Scores
            scores_tprf = mean(squeeze(scores_roc(1, :, net_id, 1, 1, :)),2);
            scores_auc_tmp = mean(scores_auc(1, net_id, 1, :));
            % Seed
            seed_tprf = mean(squeeze(seed_roc(1, :, net_id, 1, 1, :)),2);
            seed_auc_tmp = mean(seed_auc(1, net_id, 1, :));
            % Dureg
            dureg_tprf = mean(squeeze(dureg_roc(1, :, net_id, 1, 1, :)),2);
            dureg_auc_tmp = mean(dureg_auc(1, net_id, 1, :));
        else
            % Scores
            scores_tprf = mean(squeeze(scores_roc(2, :, net_id, 1, noise_id, :)),2);
            scores_auc_tmp = mean(scores_auc(2, net_id, noise_id, :));
            % Seed
            seed_tprf = mean(squeeze(seed_roc(2, :, net_id, 1, noise_id, :)),2);
            seed_auc_tmp = mean(seed_auc(2, net_id, noise_id, :));
            % Dureg
            dureg_tprf = mean(squeeze(dureg_roc(2, :, net_id, 1, noise_id, :)),2);
            dureg_auc_tmp = mean(dureg_auc(2, net_id, noise_id, :));
        end
        
        % Scores
        pos = pos_mat(n_id+1, net_id);
        subplot(5,4,pos);
        hold on;
        % scores
        plot(ref_fpr, scores_tprf, 'g');
        % seed
        plot(ref_fpr, seed_tprf, 'r');
        % dureg
        plot(ref_fpr, dureg_tprf, 'b');
        hold off;
        labels = {sprintf('SC (%.3f)', scores_auc_tmp), sprintf('SE (%.3f)', seed_auc_tmp), sprintf('DR (%.3f)', dureg_auc_tmp)};
        if n_id == 1
            title(sprintf('%s network, no structured noise', net_names{net_id}));
        else
            title(sprintf('%s network, noise %.1f', net_names{net_id}, noise_levels(noise_id)));
        end
        legend(labels, 'Location', 'southeast');
    end
end

set(fig,'PaperPositionMode','auto');
print(fig, [fig_path filesep 'roc_overview.png'], '-dpng');

%% 4. AUC plot
f_auc = figure('position',[0 0 1500 2400]);
labels = [{'no structural noise'}; cellstr(num2str(noise_levels'))];
for net_id = 1:n_nets
    network_id = networks(net_id);
    net_name = net_names{net_id};
    % Get the average AUC values
    auc_all = [[mean(squeeze(scores_auc(1, net_id, 1, :))); mean(squeeze(scores_auc(2, net_id, :, :)),2)],...
               [mean(squeeze(seed_auc(1, net_id, 1, :))); mean(squeeze(seed_auc(2, net_id, :, :)),2)],...
               [mean(squeeze(dureg_auc(2, net_id, 1, :))); mean(squeeze(dureg_auc(2, net_id, :, :)),2)]];
    std_all = [[std(squeeze(scores_auc(1, net_id, 1, :))); std(squeeze(scores_auc(2, net_id, :, :)),[],2)],...
               [std(squeeze(seed_auc(1, net_id, 1, :))); std(squeeze(seed_auc(2, net_id, :, :)),[],2)],...
               [std(squeeze(dureg_auc(1, net_id, 1, :))); std(squeeze(dureg_auc(2, net_id, :, :)),[],2)]];
    
    subplot(4,1,net_id)
    % Combine them all into one big plot
    barwitherr(std_all, auc_all);
    legend({'scores', 'seed', 'dual regression'}, 'Location', 'eastoutside');
    title(sprintf('AUC for %s network', net_name));
    set(gca,'xlim',[0 5],'ylim', [0.3 1], 'XTickLabel', labels);
    xlabel('noise level');
    ylabel('AUC');
end
set(f_auc,'PaperPositionMode','auto');
print(f_auc, [fig_path filesep 'auc_overview.png'], '-dpng');

%% Mass-Univariate Ttest of AUC

% Make a storage for the values
% 1 - types of values (8 t, p, mean, std, df, pooled_std, cohensd, bonferroni)
% 2 - values (noise levels)
% 3 - tests (3: scores/seed, scores/dureg, seed/dureg)
% 4 - networks
t_auc_store = zeros(8, 3, 3, n_nets);
q = 0.01;
for net_id = 1:n_nets
    network_id = networks(net_id);
    net_name = net_names{net_id};
    % Get the average AUC values
    tmp_scores_auc = squeeze(scores_auc(2, net_id, :, :))';
    tmp_seed_auc = squeeze(seed_auc(2, net_id, :, :))';
    tmp_dureg_auc = squeeze(dureg_auc(2, net_id, :, :))';
    % Run the t-test
    % 1 scores-seed
    [t1, p1, m1, s1, d1] = niak_ttest(tmp_scores_auc, tmp_seed_auc, true);
    % 2 scores-dureg
    [t2, p2, m2, s2, d2] = niak_ttest(tmp_scores_auc, tmp_dureg_auc, true);
    % 3 seed-dureg
    [t3, p3, m3, s3, d3] = niak_ttest(tmp_seed_auc, tmp_dureg_auc, true);
    % Store the stuff
    t_auc_store(1:5, :, 1, net_id) = [t1; p1; m1; s1; d1];
    t_auc_store(1:5, :, 2, net_id) = [t2; p2; m2; s2; d2];
    t_auc_store(1:5, :, 3, net_id) = [t3; p3; m3; s3; d3];
    % Add the pooled variance
    t_auc_store(6, :, 1, net_id) = ( (( n_perm - 1) .* std(tmp_scores_auc)) + (( n_perm - 1) .* std(tmp_seed_auc))) / (n_perm + n_perm -2);
    t_auc_store(6, :, 2, net_id) = ( (( n_perm - 1) .* std(tmp_scores_auc)) + (( n_perm - 1) .* std(tmp_dureg_auc))) / (n_perm + n_perm -2);
    t_auc_store(6, :, 3, net_id) = ( (( n_perm - 1) .* std(tmp_seed_auc)) + (( n_perm - 1) .* std(tmp_dureg_auc))) / (n_perm + n_perm -2);
    % Compute Cohensd
    t_auc_store(7, :, 1, net_id) = t_auc_store(3, :, 1, net_id) ./ t_auc_store(6, :, 1, net_id);
    t_auc_store(7, :, 2, net_id) = t_auc_store(3, :, 2, net_id) ./ t_auc_store(6, :, 2, net_id);
    t_auc_store(7, :, 3, net_id) = t_auc_store(3, :, 3, net_id) ./ t_auc_store(6, :, 3, net_id);
end
% Do the bonferroni correction
p = squeeze(t_auc_store(2, :, :, :));
p_mask = p < q/numel(p);
t_auc_store(8, :, :, :) = p_mask;
save([fig_path filesep 'ttest_results_auc.mat'], 't_auc_store');

%% Show the results in a nice way
%load([fig_path filesep 'ttest_results_auc.mat']);
for net_id = 1:n_nets
    network_id = networks(net_id);
    net_name = net_names{net_id};
    fprintf('%s network\n', net_name);
    test_name = {'scores vs seed', 'scores vs dureg', 'seed vs dureg'};
    for t_id = 1:3
        fprintf('    %s\n', test_name{t_id});
        pval = t_auc_store(2, :, t_id, net_id)';
        bonf =  t_auc_store(8, :, t_id, net_id)';
        pval(~bonf) = 1;
        effect =  t_auc_store(7, :, t_id, net_id)';
        tval =  t_auc_store(1, :, t_id, net_id)';
        df =  t_auc_store(5, :, t_id, net_id)';
        T = table(bonf, pval, tval, df, effect, 'RowNames', cellstr(num2str(noise_levels')))
    end
end

%% Plot the FPR and TPR curves over the thresholds

pos_mat = reshape(1:12, [3 4])';
figs = cell(n_nets, 1);
% iterate across networks
for net_id = 1:n_nets
    network = networks(net_id);
    n_pos = net_id+1;
    figs{net_id} = figure('position',[0 0 1600 1200]);%, 'visible','off');
    clf;
    suptitle(sprintf('%s network', net_names{net_id}));
    % Iterate across noise levels, last one is clean
    for n_id  = 1:4
        noise_id = n_id - 1;
        if n_id == 1
            % Scores
            scores_tprt = mean(squeeze(scores_roc(1, :, net_id, 2, 1, :)),2);
            scores_fprt = mean(squeeze(scores_roc(1, :, net_id, 3, 1, :)),2);
            scores_ab = (trapz(ref_thr, scores_tprt) - trapz(ref_thr, scores_fprt))/2;
            % Seed
            seed_tprt = mean(squeeze(seed_roc(1, :, net_id, 2, 1, :)),2);
            seed_fprt = mean(squeeze(seed_roc(1, :, net_id, 3, 1, :)),2);
            seed_ab = (trapz(ref_thr, seed_tprt) - trapz(ref_thr, seed_fprt))/2;
            % Dureg
            dureg_tprt = mean(squeeze(dureg_roc(1, :, net_id, 2, 1, :)),2);
            dureg_fprt = mean(squeeze(dureg_roc(1, :, net_id, 3, 1, :)),2);
            dureg_ab = (trapz(ref_thr, dureg_tprt) - trapz(ref_thr, dureg_fprt))/2;
        else
            % Scores
            scores_tprt = mean(squeeze(scores_roc(2, :, net_id, 2, noise_id, :)),2);
            scores_fprt = mean(squeeze(scores_roc(2, :, net_id, 3, noise_id, :)),2);
            scores_ab = (trapz(ref_thr, scores_tprt) - trapz(ref_thr, scores_fprt))/2;
            % Seed
            seed_tprt = mean(squeeze(seed_roc(2, :, net_id, 2, noise_id, :)),2);
            seed_fprt = mean(squeeze(seed_roc(2, :, net_id, 3, noise_id, :)),2);
            seed_ab = (trapz(ref_thr, seed_tprt) - trapz(ref_thr, seed_fprt))/2;
            % Dureg
            dureg_tprt = mean(squeeze(dureg_roc(2, :, net_id, 2, noise_id, :)),2);
            dureg_fprt = mean(squeeze(dureg_roc(2, :, net_id, 3, noise_id, :)),2);
            dureg_ab = (trapz(ref_thr, dureg_tprt) - trapz(ref_thr, dureg_fprt))/2;
        end        
        % Scores
        pos = pos_mat(n_id, 1);
        subplot(4,3,pos);
        hold on;
        % Generate filled area
        X = [ref_thr, fliplr(ref_thr)];
        Y = [scores_fprt', fliplr(scores_tprt')];
        h = fill(X, Y, 'b');
        %set(h,'facealpha',.1);
        plot(ref_thr, scores_tprt, 'g');
        plot(ref_thr, scores_fprt, 'r');
        hold off;
        legend({sprintf('TPR-FPR (%.3f)', scores_ab), 'TPR', 'FPR'}, 'Location', 'southwest');
        if n_id == 1
            title('Scores');
        end
        if n_id == 1
            ylabel('no structured noise');
        else
            ylabel(sprintf('noise %.3f', noise_levels(noise_id)));
        end
        
        % Seed
        pos = pos_mat(n_id, 2);
        subplot(4,3,pos);
        hold on;
        % Generate filled area
        X = [ref_thr, fliplr(ref_thr)];
        Y = [seed_fprt', fliplr(seed_tprt')];
        h = fill(X, Y, 'b');
        %set(h,'facealpha',.1);
        plot(ref_thr, seed_tprt, 'g');
        plot(ref_thr, seed_fprt, 'r');
        hold off;
        legend({sprintf('TPR-FPR (%.3f)', seed_ab), 'TPR', 'FPR'}, 'Location', 'southwest');
        if n_id == 1
            title('Seed');
        end
        
        % Dureg
        pos = pos_mat(n_id, 3);
        subplot(4,3,pos);
        hold on;
        % Generate filled area
        X = [ref_thr, fliplr(ref_thr)];
        Y = [dureg_fprt', fliplr(dureg_tprt')];
        h = fill(X, Y, 'b');
        %set(h,'facealpha',.1);
        plot(ref_thr, dureg_tprt, 'g');
        plot(ref_thr, dureg_fprt, 'r');
        hold off;
        legend({sprintf('TPR-FPR (%.3f)', dureg_ab), 'TPR', 'FPR'}, 'Location', 'southwest');
        if n_id == 1
            title('Dual Regression');
        end
    end
    set(gcf,'PaperPositionMode','auto');
    print(gcf, [fig_path filesep sprintf('method_separation_%s_network.png', net_names{net_id})], '-dpng');
end